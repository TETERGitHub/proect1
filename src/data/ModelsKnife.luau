--!nonstrict
-- data/ModelsKnife: detailed procedural knife models (original designs). The blade points to -Z, the handle ends at +Z.
-- Depends on: ModelKit.

local import = ...
local Kit = import("data/ModelKit")

local K = {}

-- a tapered blade built from stacked slices: length along -Z from z0, thickness t, height h0 -> h1 at the tip
local function taperBlade(b, role, z0, len, h0, h1, t, steps, y)
	steps = steps or 6
	local seg = len / steps
	for i = 0, steps - 1 do
		local k = (i + 0.5) / steps
		local h = h0 + (h1 - h0) * k
		b:box("Blade" .. i, role, t, h, seg + 0.01, 0, y or 0, z0 - seg * (i + 0.5)).m = "Metal"
	end
end

local function handleWrap(b, z0, len, dia, bands)
	b:cylZ("Handle", "grip", len, dia, 0, 0, z0 + len / 2).m = "mat"
	for i = 0, bands - 1 do
		b:cylZ("Wrap" .. i, "black", 0.04, dia + 0.03, 0, 0, z0 + (i + 0.6) * len / bands)
	end
end

-- 1. Classic ---------------------------------------------------------------------------------------------------------------
K.classic = { id = "classic", name = "Classic", category = "Classic", build = function(b)
	taperBlade(b, "primary", -0.1, 1.6, 0.52, 0.34, 0.07, 6)
	b:wedge("Point", "primary", 0.07, 0.34, 0.5, 0, 0.0, -1.95, 0, 0, 0).m = "Metal"
	b:box("Spine", "secondary", 0.1, 0.06, 1.6, 0, 0.27, -0.9).m = "mat"
	b:box("Fuller", "glow", 0.075, 0.06, 1.1, 0, 0.1, -0.7)
	b:box("Edge", "detail", 0.075, 0.04, 1.5, 0, -0.26, -0.85).m = "Metal"
	b:box("Guard", "steel", 0.16, 0.9, 0.16, 0, 0, 0.02).m = "Metal"
	b:ball("GuardTipA", "detail", 0.2, 0, 0.46, 0.02).m = "Metal"
	b:ball("GuardTipB", "detail", 0.2, 0, -0.46, 0.02).m = "Metal"
	handleWrap(b, 0.1, 1.0, 0.26, 6)
	b:ball("Pommel", "detail", 0.34, 0, 0, 1.2).m = "Metal"
	b:ball("PommelGem", "glow", 0.14, 0, 0, 1.36)
end }

-- 2. Tanto (Tactical) --------------------------------------------------------------------------------------------------------
K.tanto = { id = "tanto", name = "Tanto", category = "Tactical", build = function(b)
	taperBlade(b, "primary", -0.1, 1.4, 0.5, 0.5, 0.08, 5)
	b:wedge("Chisel", "primary", 0.08, 0.5, 0.5, 0, 0.0, -1.75, 0, 0, 0).m = "Metal"
	b:box("Bevel", "secondary", 0.09, 0.2, 1.0, 0, -0.15, -0.65).m = "mat"
	b:box("Serration", "black", 0.1, 0.06, 0.5, 0, 0.22, -0.4)
	b:box("Guard", "black", 0.18, 0.72, 0.14, 0, 0, 0.0)
	handleWrap(b, 0.07, 1.1, 0.28, 7)
	b:box("Butt", "black", 0.3, 0.36, 0.14, 0, 0, 1.22)
	b:box("Lanyard", "detail", 0.1, 0.1, 0.1, 0, -0.18, 1.3).m = "mat"
	b:box("Lume", "glow", 0.09, 0.05, 0.4, 0, 0.05, -1.2)
end }

-- 3. Karambit ------------------------------------------------------------------------------------------------------------------
K.karambit = { id = "karambit", name = "Karambit", category = "Classic", build = function(b)
	-- the blade is a hooked arc: slices follow a circle that curves downward from the handle, narrowing to a point
	local segs, R = 12, 1.15
	for i = 0, segs - 1 do
		local t = i / (segs - 1)
		local th = math.rad(8 + 95 * t)
		local h = 0.36 * (1 - 0.82 * t) + 0.05
		local y, z = -R * (1 - math.cos(th)), -0.05 - R * math.sin(th)
		local rx = -math.deg(th)
		b:box("Seg" .. i, "primary", 0.07, h, 0.22, 0, y, z, rx, 0, 0).m = "Metal"
		-- cutting edge on the inner (concave) side
		local ey, ez = y - h / 2 * math.cos(th), z + h / 2 * math.sin(th)
		b:box("Edge" .. i, "glow", 0.075, 0.03, 0.2, 0, ey, ez, rx, 0, 0)
	end
	b:box("Spine", "secondary", 0.09, 0.05, 0.5, 0, 0.2, -0.25).m = "mat"
	b:box("Bolster", "steel", 0.2, 0.42, 0.14, 0, 0.0, 0.02).m = "Metal"
	b:box("Handle", "grip", 0.24, 0.3, 0.85, 0, 0.0, 0.52).m = "mat"
	for i = 0, 4 do b:box("Ridge" .. i, "black", 0.26, 0.32, 0.04, 0, 0.0, 0.25 + i * 0.16) end
	b:cylX("Ring", "detail", 0.1, 0.62, 0, -0.14, 1.08).m = "Metal"
	b:cylX("RingHole", "black", 0.12, 0.34, 0, -0.14, 1.08)
	b:ball("Gem", "glow", 0.12, 0, 0.08, 0.02)
end }

-- 4. Dagger (Neon) -------------------------------------------------------------------------------------------------------------
K.dagger = { id = "dagger", name = "Dagger", category = "Neon", build = function(b)
	taperBlade(b, "secondary", -0.1, 1.9, 0.44, 0.1, 0.06, 8)
	b:wedge("Tip", "secondary", 0.06, 0.1, 0.25, 0, 0, -2.12, 0, 0, 0).m = "Metal"
	b:box("Core", "glow", 0.075, 0.05, 1.8, 0, 0, -1.0)
	b:mirror(function(s) b:box("Rune" .. s, "glow", 0.01, 0.2, 0.05, s * 0.04, 0, -0.4) end)
	b:wedge("GuardL", "primary", 0.12, 0.3, 0.5, 0, 0.5, 0.0, 0, 0, 0).m = "mat"
	b:wedge("GuardR", "primary", 0.12, 0.3, 0.5, 0, -0.5, 0.0, 180, 0, 0).m = "mat"
	b:box("GuardMid", "primary", 0.14, 0.7, 0.2, 0, 0, 0.02).m = "mat"
	handleWrap(b, 0.12, 0.9, 0.24, 5)
	b:cylZ("Pommel", "primary", 0.18, 0.4, 0, 0, 1.12).m = "mat"
	b:ball("PommelGlow", "glow", 0.22, 0, 0, 1.25)
end }

-- 5. Kris (Shadow) ----------------------------------------------------------------------------------------------------------------
K.kris = { id = "kris", name = "Kris", category = "Shadow", build = function(b)
	-- wavy blade: alternate lateral offsets along the length
	local n = 12
	for i = 0, n - 1 do
		local t = i / (n - 1)
		local x = math.sin(t * math.pi * 3) * 0.1
		b:box("Wave" .. i, "primary", 0.07, 0.34 * (1 - 0.75 * t) + 0.05, 0.28, x, 0, -0.2 - i * 0.17).m = "Metal"
		b:box("Glint" .. i, "glow", 0.075, 0.025, 0.2, x, 0, -0.2 - i * 0.17)
	end
	b:wedge("Base", "secondary", 0.1, 0.5, 0.4, 0, 0.0, -0.05, 0, 0, 0).m = "mat"
	b:box("Guard", "secondary", 0.16, 0.7, 0.16, 0, 0, 0.1).m = "mat"
	b:box("Handle", "grip", 0.22, 0.26, 0.8, 0, 0, 0.6).m = "mat"
	for i = 0, 3 do b:box("Wrap" .. i, "black", 0.24, 0.28, 0.04, 0, 0, 0.35 + i * 0.18) end
	b:wedge("Hook", "secondary", 0.2, 0.4, 0.4, 0, 0.1, 1.15, 0, 0, 0).m = "mat"
	b:ball("Eye", "glow", 0.1, 0, 0.0, 0.12)
end }

-- 6. Crystal ---------------------------------------------------------------------------------------------------------------------
K.crystal = { id = "crystal", name = "Crystal", category = "Crystal", build = function(b)
	taperBlade(b, "primary", -0.1, 1.5, 0.5, 0.2, 0.1, 5)
	for _, part in ipairs(b.parts) do if string.sub(part.n, 1, 5) == "Blade" then part.decor = true; part.m = "Glass" end end
	b:wedge("Point", "primary", 0.1, 0.2, 0.5, 0, 0, -1.85, 0, 0, 0).decor = true
	b:last().m = "Glass"
	b:box("Core", "glow", 0.06, 0.06, 1.5, 0, 0, -0.9)
	-- side shards
	for i = 0, 3 do
		local z = -0.3 - i * 0.35
		b:wedge("ShardA" .. i, "secondary", 0.07, 0.28 - i * 0.04, 0.3, 0.07, 0.3 - i * 0.04, z, 0, 0, 20).m = "Glass"
		b:last().decor = true
		b:wedge("ShardB" .. i, "secondary", 0.07, 0.28 - i * 0.04, 0.3, -0.07, -0.3 + i * 0.04, z, 180, 0, -20).m = "Glass"
		b:last().decor = true
	end
	b:box("Collar", "detail", 0.18, 0.6, 0.22, 0, 0, 0.05).m = "Metal"
	b:cylZ("Handle", "grip", 0.9, 0.24, 0, 0, 0.65).m = "mat"
	b:ball("Orb", "glow", 0.3, 0, 0, 1.25)
end }

-- 7. Slim (Minimal) -------------------------------------------------------------------------------------------------------------
K.slim = { id = "slim", name = "Slim", category = "Minimal", build = function(b)
	taperBlade(b, "primary", -0.05, 1.8, 0.34, 0.12, 0.05, 6)
	b:wedge("Tip", "primary", 0.05, 0.12, 0.3, 0, 0, -1.95, 0, 0, 0).m = "Metal"
	b:box("Line", "glow", 0.055, 0.02, 1.5, 0, 0.04, -0.9)
	b:box("Ricasso", "secondary", 0.07, 0.34, 0.1, 0, 0, 0.0).m = "mat"
	b:box("Handle", "grip", 0.16, 0.22, 1.1, 0, 0, 0.6).m = "mat"
	b:box("Cap", "secondary", 0.18, 0.24, 0.06, 0, 0, 1.17).m = "mat"
end }

-- 8. Cleaver ---------------------------------------------------------------------------------------------------------------------
K.cleaver = { id = "cleaver", name = "Cleaver", category = "Shadow", build = function(b)
	b:box("Blade", "primary", 0.09, 1.15, 1.35, 0, 0.12, -0.8).m = "Metal"
	b:box("Edge", "glow", 0.095, 0.05, 1.3, 0, -0.45, -0.8)
	b:box("Spine", "secondary", 0.13, 0.08, 1.4, 0, 0.72, -0.8).m = "mat"
	b:cylZ("HangHole", "black", 0.1, 0.16, 0, 0.35, -1.1)
	b:box("Bevel", "detail", 0.1, 0.3, 0.1, 0, 0.12, -1.5).m = "Metal"
	b:box("Neck", "steel", 0.1, 0.3, 0.3, 0, 0.5, 0.0).m = "Metal"
	b:box("Handle", "grip", 0.26, 0.3, 1.1, 0, 0.5, 0.65).m = "mat"
	for i = 0, 2 do b:ball("Rivet" .. i, "detail", 0.1, 0.14, 0.5, 0.3 + i * 0.35).m = "Metal" end
	b:box("Butt", "secondary", 0.28, 0.32, 0.1, 0, 0.5, 1.22).m = "mat"
end }

K.order = { "classic", "tanto", "karambit", "dagger", "kris", "crystal", "slim", "cleaver" }

K.styles = {
	{ id = "Classic", look = { primary = { 196, 202, 212 }, secondary = { 120, 126, 138 }, grip = { 98, 62, 36 }, detail = { 196, 154, 72 }, glow = { 255, 214, 120 }, material = "Metal", glowAmount = 0.2, decor = 0 } },
	{ id = "Tactical", look = { primary = { 70, 76, 62 }, secondary = { 46, 50, 40 }, grip = { 30, 32, 28 }, detail = { 110, 118, 96 }, glow = { 255, 170, 60 }, material = "Metal", glowAmount = 0.3, decor = 0 } },
	{ id = "Futuristic", look = { primary = { 236, 240, 248 }, secondary = { 130, 140, 160 }, grip = { 60, 66, 80 }, detail = { 170, 180, 200 }, glow = { 80, 210, 255 }, material = "SmoothPlastic", glowAmount = 0.9, decor = 0 } },
	{ id = "Neon", look = { primary = { 30, 22, 52 }, secondary = { 56, 30, 100 }, grip = { 20, 16, 34 }, detail = { 255, 80, 200 }, glow = { 255, 60, 220 }, material = "SmoothPlastic", glowAmount = 1, decor = 0 } },
	{ id = "Shadow", look = { primary = { 40, 38, 48 }, secondary = { 24, 22, 30 }, grip = { 16, 14, 20 }, detail = { 90, 70, 130 }, glow = { 150, 70, 255 }, material = "Metal", glowAmount = 0.7, decor = 0 } },
	{ id = "Metallic", look = { primary = { 210, 214, 224 }, secondary = { 150, 156, 168 }, grip = { 90, 94, 104 }, detail = { 240, 200, 120 }, glow = { 255, 240, 200 }, material = "Foil", glowAmount = 0.15, decor = 0 } },
	{ id = "Crystal", look = { primary = { 150, 220, 255 }, secondary = { 110, 170, 255 }, grip = { 50, 70, 110 }, detail = { 220, 240, 255 }, glow = { 120, 230, 255 }, material = "Glass", glowAmount = 0.8, decor = 0.25 } },
	{ id = "Minimal", look = { primary = { 238, 238, 242 }, secondary = { 214, 214, 220 }, grip = { 60, 60, 66 }, detail = { 120, 120, 128 }, glow = { 10, 132, 255 }, material = "SmoothPlastic", glowAmount = 0.35, decor = 0 } },
}

return K
