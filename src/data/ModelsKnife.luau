--!nonstrict
-- data/ModelsKnife: knife models (original designs, Part primitives only). The blade points to -Z, the handle ends at +Z,
-- the cutting edge is the lower edge (-Y). Blades and handles are polygons (see ModelKit:poly) so every knife has its own
-- silhouette: drop point, tanto, curved karambit, double-edged dagger, wavy kris, crystal, stiletto and cleaver.
-- `hold` is the point the hand grips (model coordinates).
-- Depends on: ModelKit.

local import = ...
local Kit = import("data/ModelKit")

local K = {}

-- ring of wrap bands round a handle running along z (cylinder-like handles)
local function bands(b, z0, count, step, dia, thick)
	for i = 0, count - 1 do
		b:cylZ("Band" .. i, "black", thick or 0.04, dia, 0, 0, z0 + i * step)
	end
end

-- thin lines on a flat blade: fuller (glow) and a polished edge strip
local function fuller(b, z0, z1, y, thick)
	b:box("Fuller", "glow", thick, 0.04, z1 - z0, 0, y, (z0 + z1) / 2)
end

-- 1. Classic drop-point hunting knife --------------------------------------------------------------------------------------------
K.classic = { id = "classic", name = "Classic", category = "Classic", hold = { 0, 0, 0.65 }, build = function(b)
	b:poly("Blade", "primary", 0.07, 0, { { -0.1, 0.27 }, { -1.5, 0.27 }, { -2.1, 0.02 }, { -1.8, -0.22 }, { -1.15, -0.33 }, { -0.5, -0.33 }, { -0.1, -0.25 } }, "Metal")
	b:poly("Edge", "detail", 0.085, 0, { { -0.5, -0.28 }, { -1.15, -0.28 }, { -1.8, -0.2 }, { -1.82, -0.24 }, { -1.15, -0.34 }, { -0.5, -0.34 } }, "Metal")
	b:poly("Spine", "secondary", 0.11, 0, { { -0.1, 0.27 }, { -1.5, 0.27 }, { -1.62, 0.21 }, { -0.1, 0.21 } }, "mat")
	fuller(b, -1.3, -0.3, 0.06, 0.075)
	-- guard with rounded quillons
	b:box("Guard", "steel", 0.16, 0.86, 0.14, 0, -0.02, 0.0).m = "Metal"
	b:ball("QuillonTop", "detail", 0.2, 0, 0.44, 0.0).m = "Metal"
	b:ball("QuillonBottom", "detail", 0.2, 0, -0.48, 0.0).m = "Metal"
	-- contoured handle with finger swells
	b:poly("Handle", "grip", 0.27, 0, { { 0.06, 0.2 }, { 0.42, 0.22 }, { 0.62, 0.16 }, { 0.86, 0.22 }, { 1.14, 0.25 }, { 1.26, 0.12 }, { 1.26, -0.12 }, { 1.14, -0.25 }, { 0.86, -0.22 }, { 0.62, -0.16 }, { 0.42, -0.22 }, { 0.06, -0.2 } }, "mat")
	for i = 0, 3 do b:box("Groove" .. i, "black", 0.29, 0.34, 0.03, 0, 0, 0.3 + i * 0.22) end
	b:ball("Pommel", "detail", 0.34, 0, 0, 1.32).m = "Metal"
	b:ball("PommelGem", "glow", 0.13, 0, 0, 1.47)
	b:ball("Lanyard", "steel", 0.08, 0, -0.1, 1.3)
end }

-- 2. Tanto (angular point, flat grind) ---------------------------------------------------------------------------------------------
K.tanto = { id = "tanto", name = "Tanto", category = "Tactical", hold = { 0, 0, 0.7 }, build = function(b)
	b:poly("Blade", "primary", 0.075, 0, { { -0.1, 0.3 }, { -1.72, 0.3 }, { -2.1, 0.04 }, { -1.74, -0.27 }, { -0.1, -0.27 } }, "Metal")
	b:poly("Bevel", "secondary", 0.09, 0, { { -0.1, -0.1 }, { -1.74, -0.1 }, { -1.74, -0.27 }, { -0.1, -0.27 } }, "mat")
	b:poly("TipBevel", "detail", 0.085, 0, { { -1.72, 0.3 }, { -2.1, 0.04 }, { -1.74, -0.1 }, { -1.74, 0.3 } }, "Metal")
	b:box("Hamon", "glow", 0.082, 0.035, 1.5, 0, -0.06, -0.9)
	b:box("Serration", "black", 0.1, 0.05, 0.55, 0, 0.26, -0.4)
	b:cylZ("Tsuba", "black", 0.07, 0.78, 0, 0, 0.02)
	b:cylZ("Habaki", "detail", 0.12, 0.42, 0, 0, -0.08).m = "Metal"
	b:cylZ("Handle", "grip", 1.1, 0.3, 0, 0, 0.68).m = "mat"
	-- diamond wrap: crossed thin bars along the handle
	for i = 0, 5 do
		b:box("WrapA" .. i, "black", 0.31, 0.04, 0.2, 0, 0.1, 0.25 + i * 0.17, 40, 0, 0)
		b:box("WrapB" .. i, "black", 0.31, 0.04, 0.2, 0, -0.1, 0.25 + i * 0.17, -40, 0, 0)
	end
	b:cylZ("Kashira", "black", 0.14, 0.34, 0, 0, 1.28).m = "Metal"
	b:ball("Cord", "detail", 0.14, 0, -0.2, 1.35).m = "mat"
end }

-- 3. Karambit: a hooked blade built from an arc outline ------------------------------------------------------------------------
K.karambit = { id = "karambit", name = "Karambit", category = "Classic", hold = { 0, 0, 0.55 }, build = function(b)
	local R, n = 1.1, 14
	local outer, inner = {}, {}
	for i = 0, n do
		local t = i / n
		local th = math.rad(6 + 100 * t)
		local w = 0.34 * (1 - 0.86 * t) + 0.03
		local cz, cy = -0.05, -R -- centre of curvature (z, y)
		table.insert(outer, { cz - (R + w * 0.15) * math.sin(th), cy + (R + w * 0.15) * math.cos(th) })
		table.insert(inner, { cz - (R - w * 0.85) * math.sin(th), cy + (R - w * 0.85) * math.cos(th) })
	end
	local pts = {}
	for _, p in ipairs(outer) do table.insert(pts, p) end
	for i = #inner, 1, -1 do table.insert(pts, inner[i]) end
	b:poly("Blade", "primary", 0.075, 0, pts, "Metal")
	-- glowing edge along the inner curve
	local edge = {}
	for _, p in ipairs(inner) do table.insert(edge, p) end
	b:stroke("Edge", "glow", 0.085, 0, edge, 0.035)
	b:poly("Spine", "secondary", 0.11, 0, { outer[1], outer[4], { outer[4][1], outer[4][2] - 0.08 }, { outer[1][1], outer[1][2] - 0.08 } }, "mat")
	-- bolster, handle with ridges, and the finger ring
	b:box("Bolster", "steel", 0.2, 0.46, 0.14, 0, 0.0, 0.04).m = "Metal"
	b:poly("Handle", "grip", 0.25, 0, { { 0.1, 0.22 }, { 0.7, 0.2 }, { 1.0, 0.14 }, { 1.0, -0.22 }, { 0.7, -0.24 }, { 0.1, -0.22 } }, "mat")
	for i = 0, 5 do b:box("Ridge" .. i, "black", 0.27, 0.46, 0.035, 0, -0.01, 0.22 + i * 0.13) end
	b:cylX("Ring", "detail", 0.1, 0.7, 0, -0.18, 1.15).m = "Metal"
	b:cylX("RingHole", "black", 0.12, 0.42, 0, -0.18, 1.15)
	b:ball("Gem", "glow", 0.12, 0, 0.1, 0.05)
end }

-- 4. Dagger (double-edged, winged guard) --------------------------------------------------------------------------------------------
K.dagger = { id = "dagger", name = "Dagger", category = "Neon", hold = { 0, 0, 0.62 }, build = function(b)
	b:poly("Blade", "secondary", 0.06, 0, { { -0.1, 0.25 }, { -1.1, 0.21 }, { -2.2, 0.0 }, { -1.1, -0.21 }, { -0.1, -0.25 } }, "Metal")
	b:poly("Ridge", "primary", 0.1, 0, { { -0.1, 0.05 }, { -1.9, 0.0 }, { -0.1, -0.05 } }, "mat")
	b:box("Core", "glow", 0.11, 0.03, 1.7, 0, 0, -1.0)
	b:mirror(function(s) b:box("Rune" .. s, "glow", 0.01, 0.16, 0.04, s * 0.052, 0, -0.5) end)
	-- winged crossguard
	b:poly("GuardTop", "primary", 0.12, 0, { { 0.12, 0.08 }, { -0.1, 0.12 }, { -0.28, 0.62 }, { 0.0, 0.5 }, { 0.16, 0.3 } }, "mat")
	b:poly("GuardBottom", "primary", 0.12, 0, { { 0.12, -0.08 }, { -0.1, -0.12 }, { -0.28, -0.62 }, { 0.0, -0.5 }, { 0.16, -0.3 } }, "mat")
	b:box("GuardMid", "primary", 0.14, 0.34, 0.24, 0, 0, 0.0).m = "mat"
	b:cylZ("Handle", "grip", 0.95, 0.24, 0, 0, 0.7).m = "mat"
	bands(b, 0.35, 5, 0.17, 0.27)
	b:cylZ("Pommel", "primary", 0.18, 0.42, 0, 0, 1.28).m = "mat"
	b:ball("Orb", "glow", 0.26, 0, 0, 1.45)
end }

-- 5. Kris (wavy blade) -----------------------------------------------------------------------------------------------------------
K.kris = { id = "kris", name = "Kris", category = "Shadow", hold = { 0, 0, 0.7 }, build = function(b)
	local n, top, bot = 26, {}, {}
	for i = 0, n do
		local t = i / n
		local zc = -0.1 - 2.1 * t
		local wave = math.sin(t * math.pi * 5) * 0.09
		local half = 0.3 * (1 - t) ^ 0.8 + 0.015
		table.insert(top, { zc, wave + half })
		table.insert(bot, { zc, wave - half })
	end
	local pts = {}
	for _, p in ipairs(top) do table.insert(pts, p) end
	for i = #bot, 1, -1 do table.insert(pts, bot[i]) end
	b:poly("Blade", "primary", 0.07, 0, pts, "Metal")
	local mid = {}
	for i = 0, n, 1 do mid[#mid + 1] = { top[i + 1][1], (top[i + 1][2] + bot[i + 1][2]) / 2 } end
	b:stroke("Glint", "glow", 0.08, 0, mid, 0.03)
	-- ganja guard (wide asymmetric shield) and a bent handle
	b:poly("Ganja", "secondary", 0.12, 0, { { 0.18, 0.1 }, { -0.12, 0.36 }, { -0.32, 0.18 }, { -0.3, -0.38 }, { 0.02, -0.5 }, { 0.2, -0.2 } }, "mat")
	b:poly("Handle", "grip", 0.24, 0, { { 0.18, 0.12 }, { 0.8, 0.1 }, { 1.2, 0.2 }, { 1.45, 0.02 }, { 1.2, -0.18 }, { 0.8, -0.16 }, { 0.18, -0.14 } }, "mat")
	for i = 0, 3 do b:box("Wrap" .. i, "black", 0.26, 0.3, 0.035, 0, -0.02, 0.35 + i * 0.2) end
	b:ball("Eye", "glow", 0.11, 0, 0.0, 0.0)
end }

-- 6. Crystal ---------------------------------------------------------------------------------------------------------------------------
K.crystal = { id = "crystal", name = "Crystal", category = "Crystal", hold = { 0, 0, 0.68 }, build = function(b)
	b:poly("Blade", "primary", 0.09, 0, { { -0.1, 0.3 }, { -1.3, 0.34 }, { -2.2, 0.02 }, { -1.4, -0.28 }, { -0.1, -0.3 } }, "Glass")
	for _, part in ipairs(b.parts) do
		if part.poly == "Blade" then part.decor = true end
	end
	b:box("Core", "glow", 0.07, 0.07, 1.8, 0, 0, -1.0)
	-- crystal shards growing out of the blade at different angles
	local shards = { { -0.5, 0.22, 24, 0.5 }, { -0.95, 0.26, -18, 0.55 }, { -1.4, 0.24, 30, 0.42 }, { -0.7, -0.22, 160, 0.42 }, { -1.2, -0.2, 200, 0.4 } }
	for i, sh in ipairs(shards) do
		local z, y, ang, len = sh[1], sh[2], sh[3], sh[4]
		local pt = b:wedge("Shard" .. i, "secondary", 0.1, len, 0.18, 0.06, y + (y > 0 and len / 2 or -len / 2), z, ang * (y > 0 and 1 or 0.0), 0, 0)
		pt.m = "Glass"
		pt.decor = true
		b:wedge("ShardB" .. i, "secondary", 0.1, len * 0.8, 0.16, -0.06, y + (y > 0 and len * 0.4 or -len * 0.4), z - 0.08, 180, 0, 0).m = "Glass"
		b:last().decor = true
	end
	b:poly("Collar", "detail", 0.16, 0, { { 0.1, 0.26 }, { -0.12, 0.34 }, { -0.12, -0.34 }, { 0.1, -0.26 }, { 0.2, 0.0 } }, "Metal")
	b:cylZ("Handle", "grip", 0.9, 0.24, 0, 0, 0.7).m = "mat"
	bands(b, 0.4, 4, 0.2, 0.27)
	b:ball("Orb", "glow", 0.34, 0, 0, 1.3)
	b:cylZ("OrbCage", "detail", 0.05, 0.4, 0, 0, 1.18).m = "Metal"
end }

-- 7. Stiletto (Minimal) ---------------------------------------------------------------------------------------------------------
K.slim = { id = "slim", name = "Slim", category = "Minimal", hold = { 0, 0, 0.6 }, build = function(b)
	b:poly("Blade", "primary", 0.05, 0, { { -0.05, 0.17 }, { -1.5, 0.12 }, { -2.3, 0.0 }, { -1.5, -0.12 }, { -0.05, -0.17 } }, "Metal")
	b:poly("Ridge", "secondary", 0.08, 0, { { -0.05, 0.03 }, { -1.9, 0.0 }, { -0.05, -0.03 } }, "mat")
	b:box("Line", "glow", 0.09, 0.02, 1.2, 0, 0, -0.8)
	b:box("Ricasso", "secondary", 0.09, 0.3, 0.12, 0, 0, 0.02).m = "mat"
	b:poly("Handle", "grip", 0.16, 0, { { 0.08, 0.13 }, { 0.5, 0.1 }, { 0.9, 0.13 }, { 1.2, 0.14 }, { 1.2, -0.14 }, { 0.9, -0.13 }, { 0.5, -0.1 }, { 0.08, -0.13 } }, "mat")
	b:cylZ("Cap", "secondary", 0.08, 0.3, 0, 0, 1.25).m = "mat"
end }

-- 8. Cleaver ---------------------------------------------------------------------------------------------------------------------------
K.cleaver = { id = "cleaver", name = "Cleaver", category = "Shadow", hold = { 0, 0.4, 0.75 }, build = function(b)
	b:poly("Blade", "primary", 0.09, 0, { { 0.0, 0.8 }, { -1.55, 0.8 }, { -1.62, 0.7 }, { -1.55, -0.35 }, { -0.9, -0.42 }, { 0.0, -0.3 } }, "Metal")
	b:poly("EdgeBevel", "detail", 0.1, 0, { { -1.55, -0.3 }, { -0.9, -0.36 }, { 0.0, -0.26 }, { 0.0, -0.3 }, { -0.9, -0.42 }, { -1.55, -0.35 } }, "Metal")
	b:box("Edge", "glow", 0.095, 0.03, 1.4, 0, -0.4, -0.85)
	b:poly("Spine", "secondary", 0.14, 0, { { 0.0, 0.8 }, { -1.55, 0.8 }, { -1.55, 0.68 }, { 0.0, 0.68 } }, "mat")
	b:cylX("HangHole", "black", 0.1, 0.22, 0, 0.5, -1.2)
	b:cylX("HangRim", "steel", 0.08, 0.3, 0, 0.5, -1.2).m = "Metal"
	b:poly("Handle", "grip", 0.27, 0, { { 0.0, 0.7 }, { 0.5, 0.74 }, { 1.2, 0.72 }, { 1.4, 0.55 }, { 1.4, 0.25 }, { 1.2, 0.1 }, { 0.5, 0.14 }, { 0.0, 0.2 } }, "mat")
	for i = 0, 2 do b:ball("Rivet" .. i, "detail", 0.1, 0.14, 0.45, 0.3 + i * 0.4).m = "Metal" end
	b:ball("RivetB", "detail", 0.1, -0.14, 0.45, 0.7).m = "Metal"
	b:poly("Bolster", "steel", 0.16, 0, { { 0.0, 0.8 }, { 0.14, 0.78 }, { 0.14, 0.16 }, { 0.0, 0.2 } }, "Metal")
end }

-- 9. Katana: long curved blade, round guard, wrapped handle ------------------------------------------------------------------------
K.katana = { id = "katana", name = "Katana", category = "Katana", hold = { 0, 0, 1.0 }, build = function(b)
	local n, top, bot = 18, {}, {}
	for i = 0, n do
		local t = i / n
		local z = -0.15 - 3.4 * t
		local sori = 0.38 * t * t -- the blade rises toward the tip
		local half = 0.15 - 0.045 * t
		table.insert(top, { z, sori + half })
		table.insert(bot, { z, sori - half })
	end
	-- kissaki: the angled tip
	table.insert(top, { -3.72, 0.38 + 0.09 })
	local pts = {}
	for _, p in ipairs(top) do table.insert(pts, p) end
	for i = #bot, 1, -1 do table.insert(pts, bot[i]) end
	b:poly("Blade", "primary", 0.06, 0, pts, "Metal")
	-- hamon: the wavy temper line near the edge
	local ham = {}
	for i = 0, n do
		local t = i / n
		ham[#ham + 1] = { -0.15 - 3.4 * t, 0.38 * t * t - 0.07 + math.sin(t * 20) * 0.015 }
	end
	b:stroke("Hamon", "glow", 0.065, 0, ham, 0.03)
	local spine = {}
	for i = 0, n do
		local t = i / n
		spine[#spine + 1] = { -0.15 - 3.4 * t, 0.38 * t * t + 0.13 - 0.045 * t }
	end
	b:stroke("Spine", "secondary", 0.08, 0, spine, 0.05, "Metal")
	-- round tsuba with a rim, habaki, wrapped handle with diamond pattern, menuki and pommel cap
	b:cylZ("Tsuba", "secondary", 0.07, 0.95, 0, 0, 0.0).m = "Metal"
	b:cylZ("TsubaRim", "detail", 0.09, 0.78, 0, 0, 0.0).m = "Metal"
	b:ring(8, 0.36, function(i, a, x, z) b:ball("TsubaDot" .. i, "glow", 0.07, x, z, 0.04) end)
	b:cylZ("Habaki", "detail", 0.2, 0.3, 0, 0, -0.16).m = "Metal"
	b:cylZ("Tsuka", "grip", 1.6, 0.27, 0, 0, 0.9).m = "mat"
	for i = 0, 7 do
		b:box("WrapA" .. i, "detail", 0.29, 0.035, 0.24, 0, 0.08, 0.2 + i * 0.19, 38, 0, 0)
		b:box("WrapB" .. i, "detail", 0.29, 0.035, 0.24, 0, -0.08, 0.2 + i * 0.19, -38, 0, 0)
	end
	b:ball("Menuki", "glow", 0.12, 0.15, 0.04, 0.8)
	b:cylZ("Kashira", "secondary", 0.14, 0.34, 0, 0, 1.76).m = "Metal"
	b:ball("Tassel", "detail", 0.14, 0, -0.22, 1.82)
end }

K.order = { "classic", "tanto", "karambit", "dagger", "kris", "crystal", "slim", "cleaver", "katana" }

K.styles = {
	{ id = "Katana", look = { primary = { 214, 220, 230 }, secondary = { 196, 160, 80 }, grip = { 40, 40, 70 }, detail = { 236, 214, 150 }, glow = { 255, 130, 170 }, material = "Metal", glowAmount = 0.3, decor = 0 } },
	{ id = "Classic", look = { primary = { 196, 202, 212 }, secondary = { 120, 126, 138 }, grip = { 98, 62, 36 }, detail = { 196, 154, 72 }, glow = { 255, 214, 120 }, material = "Metal", glowAmount = 0.2, decor = 0 } },
	{ id = "Tactical", look = { primary = { 70, 76, 62 }, secondary = { 46, 50, 40 }, grip = { 30, 32, 28 }, detail = { 110, 118, 96 }, glow = { 255, 170, 60 }, material = "Metal", glowAmount = 0.3, decor = 0 } },
	{ id = "Futuristic", look = { primary = { 236, 240, 248 }, secondary = { 130, 140, 160 }, grip = { 60, 66, 80 }, detail = { 170, 180, 200 }, glow = { 80, 210, 255 }, material = "SmoothPlastic", glowAmount = 0.9, decor = 0 } },
	{ id = "Neon", look = { primary = { 30, 22, 52 }, secondary = { 56, 30, 100 }, grip = { 20, 16, 34 }, detail = { 255, 80, 200 }, glow = { 255, 60, 220 }, material = "SmoothPlastic", glowAmount = 1, decor = 0 } },
	{ id = "Shadow", look = { primary = { 92, 88, 118 }, secondary = { 48, 44, 66 }, grip = { 26, 22, 34 }, detail = { 120, 90, 170 }, glow = { 150, 70, 255 }, material = "Metal", glowAmount = 0.7, decor = 0 } },
	{ id = "Metallic", look = { primary = { 210, 214, 224 }, secondary = { 150, 156, 168 }, grip = { 90, 94, 104 }, detail = { 240, 200, 120 }, glow = { 255, 240, 200 }, material = "Foil", glowAmount = 0.15, decor = 0 } },
	{ id = "Crystal", look = { primary = { 150, 220, 255 }, secondary = { 110, 170, 255 }, grip = { 50, 70, 110 }, detail = { 220, 240, 255 }, glow = { 120, 230, 255 }, material = "Glass", glowAmount = 0.8, decor = 0.25 } },
	{ id = "Minimal", look = { primary = { 238, 238, 242 }, secondary = { 214, 214, 220 }, grip = { 60, 60, 66 }, detail = { 120, 120, 128 }, glow = { 10, 132, 255 }, material = "SmoothPlastic", glowAmount = 0.35, decor = 0 } },
}

return K
