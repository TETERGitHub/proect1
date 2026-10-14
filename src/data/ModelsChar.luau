--!nonstrict
-- data/ModelsChar: character customisation models. Two groups:
--   accessory: small attachments for one slot (head / back / aura), positioned relative to the body part they attach to
--              (head = Head centre, back = UpperTorso centre with +Z behind the character, aura = HumanoidRootPart).
--   costume:   a full-body stand-in drawn over your own avatar (origin = HumanoidRootPart, feet at y = -3, face toward -Z).
-- The costumes are blocky original interpretations of internet-meme characters built from Part primitives, NOT the
-- Blender meshes of any other project. They are visual only: welded to your own character, no collision, no stats.
-- Depends on: ModelKit.

local import = ...
local Kit = import("data/ModelKit")

local C = {}

local function eyes(b, y, z, spread, d, pupil)
	b:mirror(function(s)
		b:ball("Eye" .. s, "white", d, s * spread, y, z)
		b:ball("Pupil" .. s, "black", pupil or d * 0.45, s * spread, y, z - d * 0.38)
	end)
end

local function limb(b, name, role, x, y, z, len, dia, rx, ry, rz)
	return b:cylY(name, role, len, dia, x, y, z, rx, ry, rz)
end

local function sneaker(b, name, x, y, z, w)
	b:box(name .. "Sole", "white", w, 0.16, w * 1.9, x, y - 0.12, z - w * 0.35)
	b:box(name .. "Top", "primary", w * 0.9, 0.3, w * 1.5, x, y + 0.06, z - w * 0.2)
	b:box(name .. "Lace", "secondary", w * 0.5, 0.05, w * 0.8, x, y + 0.23, z - w * 0.35)
end

-- ACCESSORIES ----------------------------------------------------------------------------------------------------------
C.halo = { id = "halo", name = "Halo", group = "accessory", slot = "head", anchor = "Head", category = "Head", build = function(b)
	b:ring(20, 0.95, function(i, a, x, z)
		b:box("Seg" .. i, "glow", 0.22, 0.09, 0.3, x, 1.35, z, 0, -math.deg(a) + 90, 0)
	end)
	b:ring(20, 0.78, function(i, a, x, z)
		b:box("In" .. i, "detail", 0.12, 0.05, 0.2, x, 1.35, z, 0, -math.deg(a) + 90, 0).m = "Metal"
	end)
end }

C.crown = { id = "crown", name = "Crown", group = "accessory", slot = "head", anchor = "Head", category = "Head", build = function(b)
	b:cylY("Band", "primary", 0.3, 1.45, 0, 0.78, 0).m = "Metal"
	b:cylY("BandTrim", "detail", 0.06, 1.5, 0, 0.66, 0).m = "Metal"
	b:ring(8, 0.62, function(i, a, x, z)
		b:wedge("Spike" .. i, "primary", 0.2, 0.52, 0.2, x, 1.12, z, 0, -math.deg(a) + 90, 0).m = "Metal"
		b:ball("Gem" .. i, "glow", 0.14, x, 1.42, z)
	end)
	b:ball("Front", "glow", 0.26, 0, 0.78, -0.75)
end }

C.horns = { id = "horns", name = "Horns", group = "accessory", slot = "head", anchor = "Head", category = "Head", build = function(b)
	b:mirror(function(s)
		for i = 0, 4 do
			local t = i / 4
			b:cylY("Horn" .. s .. i, "primary", 0.3, 0.32 - 0.22 * t, s * (0.38 + 0.2 * t + 0.12 * t * t), 0.7 + i * 0.26, -0.05, 0, 0, s * (-14 - 10 * t)).m = "mat"
		end
		b:ball("Tip" .. s, "glow", 0.12, s * 0.82, 1.82, -0.05)
		b:ball("Base" .. s, "secondary", 0.4, s * 0.38, 0.62, -0.05).m = "mat"
	end)
end }

C.headphones = { id = "headphones", name = "Headphones", group = "accessory", slot = "head", anchor = "Head", category = "Head", build = function(b)
	b:box("Arc1", "secondary", 1.35, 0.14, 0.2, 0, 0.78, 0).m = "mat"
	b:mirror(function(s)
		b:box("ArcSide" .. s, "secondary", 0.14, 0.6, 0.2, s * 0.72, 0.5, 0, 0, 0, s * 0).m = "mat"
		b:cylX("Cup" .. s, "primary", 0.32, 0.7, s * 0.82, 0.1, 0, 0, 0, 0).m = "mat"
		b:cylX("Pad" .. s, "black", 0.14, 0.6, s * 0.62, 0.1, 0, 0, 0, 0)
		b:cylX("CupGlow" .. s, "glow", 0.05, 0.4, s * 1.0, 0.1, 0, 0, 0, 0)
	end)
end }

C.catears = { id = "catears", name = "Cat ears", group = "accessory", slot = "head", anchor = "Head", category = "Head", build = function(b)
	b:mirror(function(s)
		b:wedge("Ear" .. s, "primary", 0.18, 0.62, 0.5, s * 0.45, 0.85, 0.0, 0, 0, s * 14).m = "mat"
		b:wedge("Inner" .. s, "glow", 0.1, 0.4, 0.3, s * 0.45, 0.85, -0.12, 0, 0, s * 14)
	end)
end }

C.wings_angel = { id = "wings_angel", name = "Angel wings", group = "accessory", slot = "back", anchor = "UpperTorso", category = "Back", build = function(b)
	b:mirror(function(s)
		-- the sign trick: left wing uses negative x, so positions are mirrored explicitly
		local function side(tag, count, a0, a1, lenAt, width, role, z, edge)
			for i = 0, count - 1 do
				local t = i / math.max(1, count - 1)
				local ang = a0 + (a1 - a0) * t
				local len = lenAt(t)
				local rad = math.rad(ang)
				local cx, cy = s * (0.35 + math.cos(rad) * len / 2), 0.9 + math.sin(rad) * len / 2
				b:box(tag .. s .. i, role, len, width, 0.05, cx, cy, z, 0, 0, s * ang).m = "mat"
				if edge then
					b:box(tag .. "E" .. s .. i, "glow", len * 0.94, 0.035, 0.055, cx - s * math.sin(rad) * width * 0.5 * 0 , cy + width * 0.5, z, 0, 0, s * ang)
				end
			end
		end
		side("Pri", 9, 62, -52, function(t) return 2.9 - 1.5 * math.abs(t - 0.25) end, 0.34, "primary", 0.5, true)
		side("Cov", 7, 56, -38, function(t) return 1.9 - 0.9 * math.abs(t - 0.3) end, 0.3, "secondary", 0.46, false)
		side("Top", 4, 70, 30, function(t) return 1.1 end, 0.26, "primary", 0.43, false)
		b:ball("Joint" .. s, "detail", 0.3, s * 0.4, 0.9, 0.5).m = "Metal"
	end)
end }

C.wings_demon = { id = "wings_demon", name = "Bat wings", group = "accessory", slot = "back", anchor = "UpperTorso", category = "Back", build = function(b)
	b:mirror(function(s)
		-- finger bones fan out; the membrane between them is a row of wide thin panels
		local angles = { 70, 42, 14, -14, -42 }
		local lens = { 2.2, 2.9, 3.0, 2.6, 1.9 }
		for i, ang in ipairs(angles) do
			local rad = math.rad(ang)
			local len = lens[i]
			local cx, cy = s * (0.35 + math.cos(rad) * len / 2), 0.9 + math.sin(rad) * len / 2
			b:box("Bone" .. s .. i, "secondary", len, 0.09, 0.09, cx, cy, 0.55, 0, 0, s * ang).m = "mat"
			b:ball("Knuckle" .. s .. i, "detail", 0.12, s * (0.35 + math.cos(rad) * len), 0.9 + math.sin(rad) * len, 0.55).m = "Metal"
			if i < #angles then
				local mid = math.rad((ang + angles[i + 1]) / 2)
				local mlen = (len + lens[i + 1]) / 2 * 0.86
				local mx, my = s * (0.35 + math.cos(mid) * mlen / 2), 0.9 + math.sin(mid) * mlen / 2
				b:box("Mem" .. s .. i, "primary", mlen, 0.9, 0.035, mx, my, 0.55, 0, 0, s * (ang + angles[i + 1]) / 2).m = "mat"
			end
		end
		b:ball("Claw" .. s, "glow", 0.16, s * (0.35 + math.cos(math.rad(70)) * 2.2), 0.9 + math.sin(math.rad(70)) * 2.2, 0.55)
	end)
end }

C.cape = { id = "cape", name = "Cape", group = "accessory", slot = "back", anchor = "UpperTorso", category = "Back", build = function(b)
	b:box("Collar", "secondary", 1.4, 0.2, 0.2, 0, 0.9, 0.55).m = "mat"
	b:box("Upper", "primary", 1.5, 1.3, 0.1, 0, 0.1, 0.65, -6, 0, 0).m = "mat"
	b:box("Lower", "primary", 1.8, 1.4, 0.1, 0, -1.2, 0.85, -12, 0, 0).m = "mat"
	b:box("Hem", "glow", 1.82, 0.07, 0.11, 0, -1.9, 0.98, -12, 0, 0)
	b:ball("ClaspL", "detail", 0.2, 0.55, 0.85, 0.5).m = "Metal"
	b:ball("ClaspR", "detail", 0.2, -0.55, 0.85, 0.5).m = "Metal"
end }

C.chains = { id = "chains", name = "Chains", group = "accessory", slot = "back", anchor = "UpperTorso", category = "Back", build = function(b)
	b:mirror(function(s)
		for i = 0, 7 do
			local y = 1.0 - i * 0.34
			local x = s * (1.1 + math.sin(i * 0.5) * 0.18)
			b:box("Link" .. s .. i, i % 2 == 0 and "detail" or "glow", i % 2 == 0 and 0.24 or 0.06, 0.34, i % 2 == 0 and 0.06 or 0.24, x, y, 0.55 + (i % 2) * 0.0).m = "Metal"
		end
	end)
end }

C.circle = { id = "circle", name = "Magic circle", group = "accessory", slot = "aura", anchor = "HumanoidRootPart", category = "Aura", build = function(b)
	b:ring(28, 2.6, function(i, a, x, z) b:box("Outer" .. i, "glow", 0.2, 0.06, 0.62, x, -2.9, z, 0, -math.deg(a) + 90, 0) end)
	b:ring(20, 1.8, function(i, a, x, z) b:box("Mid" .. i, "detail", 0.14, 0.05, 0.6, x, -2.92, z, 0, -math.deg(a) + 90, 0) end)
	b:ring(3, 2.2, function(i, a, x, z)
		b:box("Tri" .. i, "glow", 0.12, 0.05, 3.0, x * 0.4, -2.88, z * 0.4, 0, -math.deg(a) + 90 + 60, 0)
	end)
	b:ring(8, 2.2, function(i, a, x, z) b:ball("Rune" .. i, "primary", 0.3, x, -2.8, z).m = "Neon" end)
end }

C.orbit = { id = "orbit", name = "Orbiting orbs", group = "accessory", slot = "aura", anchor = "HumanoidRootPart", category = "Aura", build = function(b)
	b:ring(6, 2.2, function(i, a, x, z)
		b:ball("Orb" .. i, "glow", 0.4, x, -0.2 + math.sin(i * 1.3) * 0.8, z)
		b:ball("Core" .. i, "detail", 0.22, x, -0.2 + math.sin(i * 1.3) * 0.8, z).m = "Metal"
	end)
	b:ring(24, 2.2, function(i, a, x, z) b:box("Track" .. i, "secondary", 0.05, 0.05, 0.5, x, -0.2, z, 0, -math.deg(a) + 90, 0) end)
end }

C.chainring = { id = "chainring", name = "Chain ring", group = "accessory", slot = "aura", anchor = "HumanoidRootPart", category = "Aura", build = function(b)
	b:ring(16, 2.3, function(i, a, x, z)
		local up = math.sin(i * 0.9) * 0.5
		b:box("Link" .. i, i % 2 == 0 and "detail" or "glow", i % 2 == 0 and 0.28 or 0.07, 0.4, i % 2 == 0 and 0.07 or 0.28, x, -1.0 + up, z, 0, -math.deg(a) + 90, 0).m = "Metal"
	end)
	b:ring(24, 2.8, function(i, a, x, z) b:box("Floor" .. i, "glow", 0.12, 0.05, 0.5, x, -2.9, z, 0, -math.deg(a) + 90, 0) end)
end }

-- COSTUMES -----------------------------------------------------------------------------------------------------------------
-- 1. log drummer ("Tung Sahur"-style)
C.logman = { id = "logman", name = "Tung Tung Sahur", group = "costume", category = "Costume", build = function(b)
	b:cylY("Body", "primary", 3.4, 1.5, 0, -0.5, 0).m = "Wood"
	for i = 0, 3 do b:cylY("Ring" .. i, "secondary", 0.08, 1.56, 0, -1.9 + i * 0.9, 0).m = "Wood" end
	b:cylY("TopCut", "wood", 0.06, 1.3, 0, 1.2, 0)
	eyes(b, 0.35, -0.7, 0.35, 0.5, 0.26)
	b:box("Brow", "black", 0.8, 0.07, 0.06, 0, 0.75, -0.74)
	b:box("Mouth", "black", 0.7, 0.14, 0.06, 0, -0.35, -0.76)
	b:mirror(function(s)
		limb(b, "Arm" .. s, "primary", s * 1.05, -0.3, -0.1, 1.6, 0.3, 0, 0, s * 12).m = "Wood"
		b:ball("Hand" .. s, "skin", 0.4, s * 1.2, -1.15, -0.1)
		limb(b, "Leg" .. s, "primary", s * 0.4, -2.45, 0, 1.2, 0.3, 0, 0, 0).m = "Wood"
		b:box("Foot" .. s, "black", 0.5, 0.2, 0.8, s * 0.4, -2.95, -0.15)
	end)
	-- the bat
	limb(b, "BatGrip", "wood", -1.2, -0.4, -0.5, 1.2, 0.2, 0, 0, 0)
	limb(b, "Bat", "primary", -1.2, 0.9, -0.5, 1.6, 0.5, 0, 0, 0).m = "Wood"
	b:ball("BatTip", "primary", 0.5, -1.2, 1.7, -0.5).m = "Wood"
	b:ring(6, 0.28, function(i, a, x, z) b:box("Nail" .. i, "steel", 0.05, 0.05, 0.12, -1.2 + x, 1.1 + math.sin(i) * 0.3, -0.5 + z, 0, 0, 0).m = "Metal" end)
end }

-- 2. trunk with sneakers ("Brr Brr Patapim"-style)
C.treeman = { id = "treeman", name = "Brr Brr Patapim", group = "costume", category = "Costume", build = function(b)
	b:cylY("Trunk", "primary", 2.6, 1.3, 0, 0.0, 0).m = "Wood"
	b:cylY("Neck", "primary", 0.5, 1.0, 0, 1.4, 0).m = "Wood"
	b:ball("Head", "primary", 1.3, 0, 1.8, 0).m = "Wood"
	for i = 0, 4 do b:box("Bark" .. i, "bark", 0.08, 0.5, 0.06, -0.5 + i * 0.25, 0.0 + (i % 2) * 0.5, -0.67) end
	b:ball("Nose", "skin", 0.5, 0, 1.75, -0.8)
	b:ball("NoseTip", "red", 0.22, 0, 1.75, -1.02)
	eyes(b, 2.1, -0.55, 0.3, 0.3, 0.14)
	-- leafy hair
	b:ring(7, 0.5, function(i, a, x, z) b:ball("Leaf" .. i, "leaf", 0.55, x, 2.6 + (i % 2) * 0.12, z) end)
	b:ball("LeafTop", "leaf", 0.7, 0, 2.8, 0)
	b:mirror(function(s)
		limb(b, "Arm" .. s, "primary", s * 0.95, 0.4, 0, 1.4, 0.24, 0, 0, s * 20).m = "Wood"
		limb(b, "Leg" .. s, "primary", s * 0.35, -1.9, 0, 1.2, 0.26, 0, 0, 0).m = "Wood"
		sneaker(b, "Shoe" .. s, s * 0.45, -2.8, -0.1, 0.62)
	end)
	b:ring(4, 0.5, function(i, a, x, z) b:ball("Moss" .. i, "leaf", 0.25, x, -0.5, z * 1.1) end)
end }

-- 3. crocodile bomber ("Bombardiro"-style): horizontal fuselage
C.croc = { id = "croc", name = "Bombardiro Crocodilo", group = "costume", category = "Costume", build = function(b)
	b:cylZ("Fuselage", "primary", 3.6, 1.1, 0, -0.3, 0.2).m = "mat"
	b:cylZ("Belly", "detail", 3.2, 0.9, 0, -0.55, 0.2).m = "mat"
	b:cylZ("Snout", "primary", 1.5, 0.75, 0, -0.3, -2.2).m = "mat"
	b:box("Jaw", "detail", 0.7, 0.18, 1.4, 0, -0.65, -2.2).m = "mat"
	b:ring(5, 0.25, function(i, a, x, z) end)
	for i = 0, 5 do b:box("Tooth" .. i, "white", 0.07, 0.14, 0.07, (i % 2 == 0 and 0.28 or -0.28), -0.52, -1.6 - i * 0.22) end
	eyes(b, 0.35, -1.5, 0.35, 0.3, 0.14)
	b:cylZ("Tail", "secondary", 1.8, 0.5, 0, -0.2, 2.9).m = "mat"
	b:box("TailFin", "secondary", 0.1, 1.0, 0.7, 0, 0.3, 3.7).m = "mat"
	b:mirror(function(s)
		b:box("Wing" .. s, "secondary", 2.8, 0.12, 1.1, s * 1.8, -0.2, 0.3, 0, s * -12, s * 4).m = "mat"
		b:box("Tip" .. s, "glow", 0.12, 0.14, 1.1, s * 3.2, -0.2, 0.55)
		b:box("TailW" .. s, "secondary", 1.2, 0.1, 0.5, s * 0.8, -0.2, 3.3).m = "mat"
		b:cylZ("Engine" .. s, "steel", 0.8, 0.4, s * 1.5, -0.5, -0.1)
		b:cylZ("Prop" .. s, "black", 0.06, 0.8, s * 1.5, -0.5, -0.55)
	end)
	for i = 0, 2 do
		b:ball("Bomb" .. i, "black", 0.5, 0, -1.05, -0.4 + i * 0.9)
		b:box("BombFin" .. i, "red", 0.4, 0.04, 0.12, 0, -1.05, 0.0 + i * 0.9)
	end
	b:cylZ("Cockpit", "glass", 1.0, 0.6, 0, 0.35, 0.5).m = "Glass"
end }

-- 4. shark in sneakers ("Tralalero"-style)
C.shark = { id = "shark", name = "Tralalero Tralala", group = "costume", category = "Costume", build = function(b)
	b:ball("Body", "primary", 2.2, 0, 0.0, 0.1).m = "mat"
	b:ball("Belly", "white", 1.7, 0, -0.35, -0.3)
	b:cylZ("Snout", "primary", 1.5, 1.0, 0, 0.1, -1.4).m = "mat"
	b:ball("SnoutTip", "primary", 1.0, 0, 0.1, -2.15).m = "mat"
	b:box("MouthLine", "black", 0.9, 0.07, 1.2, 0, -0.28, -1.5)
	for i = 0, 4 do b:wedge("Tooth" .. i, "white", 0.1, 0.16, 0.12, (i - 2) * 0.17, -0.22, -1.8 - (i % 2) * 0.15, 180, 0, 0) end
	eyes(b, 0.5, -1.0, 0.5, 0.36, 0.17)
	b:wedge("Dorsal", "secondary", 0.1, 1.0, 1.1, 0, 1.3, 0.3, 0, 0, 0).m = "mat"
	b:wedge("TailFin", "secondary", 0.1, 1.0, 0.8, 0, 0.5, 1.5, 0, 0, 0).m = "mat"
	b:mirror(function(s)
		b:wedge("Flipper" .. s, "secondary", 0.9, 0.12, 0.8, s * 1.2, -0.3, 0.1, 0, s * 20, 0).m = "mat"
	end)
	for i = -1, 1 do
		limb(b, "Leg" .. i, "secondary", i * 0.6, -1.9, 0.2, 1.3, 0.24, 0, 0, 0).m = "mat"
		sneaker(b, "Shoe" .. i, i * 0.6, -2.7, 0.15, 0.5)
	end
end }

-- 5. coffee-cup ninja ("Cappuccino Assassino"-style)
C.cupninja = { id = "cupninja", name = "Cappuccino Assassino", group = "costume", category = "Costume", build = function(b)
	b:cylY("Cup", "white", 2.3, 1.7, 0, 0.0, 0).m = "mat"
	b:cylY("Coffee", "bark", 0.06, 1.5, 0, 1.16, 0)
	b:cylY("Foam", "skin", 0.05, 1.1, 0, 1.2, 0)
	b:cylY("Sleeve", "primary", 0.8, 1.76, 0, -0.1, 0).m = "mat"
	b:cylX("Handle", "white", 0.14, 0.9, 1.1, 0.1, 0).m = "mat"
	b:box("Band", "red", 1.76, 0.2, 0.06, 0, 0.75, -0.0)
	b:box("BandKnot", "red", 0.3, 0.2, 0.2, 0.9, 0.75, 0.4)
	b:box("Mask", "black", 1.4, 0.4, 0.06, 0, 0.5, -0.86)
	b:mirror(function(s)
		b:ball("Eye" .. s, "white", 0.3, s * 0.35, 0.5, -0.9)
		b:ball("Pupil" .. s, "black", 0.14, s * 0.35, 0.5, -1.02)
		limb(b, "Arm" .. s, "white", s * 1.15, -0.3, -0.1, 1.1, 0.24, 0, 0, s * 18)
		b:cylZ("Blade" .. s, "steel", 2.0, 0.1, s * 1.3, -0.8, -1.1).m = "Metal"
		b:box("Guard" .. s, "black", 0.5, 0.06, 0.1, s * 1.3, -0.8, -0.1)
		limb(b, "Leg" .. s, "black", s * 0.45, -1.7, 0, 1.0, 0.26, 0, 0, 0)
		b:box("Foot" .. s, "red", 0.5, 0.2, 0.8, s * 0.45, -2.25, -0.15)
	end)
	b:ring(10, 0.75, function(i, a, x, z) b:box("Steam" .. i, "glow", 0.05, 0.05, 0.12, x * 0.4, 1.6 + i * 0.12, z * 0.4) end)
end }

-- 6. banana with a monkey head ("Chimpanzini"-style)
C.banana = { id = "banana", name = "Chimpanzini Bananini", group = "costume", category = "Costume", build = function(b)
	for i = 0, 6 do
		local t = i / 6
		b:box("Seg" .. i, "primary", 1.0 - 0.15 * math.abs(t - 0.5), 0.6, 0.9, math.sin(t * math.pi) * 0.1 - 0.05, -1.4 + i * 0.5, 0.15 - math.sin(t * math.pi) * 0.25, 0, 0, 0)
	end
	b:box("Stem", "bark", 0.2, 0.3, 0.2, 0, 1.85, 0.0)
	b:box("Ridge", "secondary", 0.08, 3.0, 0.1, 0, 0.3, -0.4)
	b:ball("Head", "wood", 1.3, 0, 2.2, -0.2)
	b:ball("Face", "skin", 0.9, 0, 2.1, -0.65)
	b:mirror(function(s)
		b:ball("Ear" .. s, "wood", 0.5, s * 0.75, 2.25, -0.2)
		b:ball("EarIn" .. s, "skin", 0.3, s * 0.78, 2.25, -0.38)
		b:ball("Eye" .. s, "white", 0.26, s * 0.25, 2.3, -1.05)
		b:ball("Pupil" .. s, "black", 0.12, s * 0.25, 2.3, -1.17)
		limb(b, "Arm" .. s, "wood", s * 0.8, 0.2, -0.3, 1.5, 0.26, 0, 0, s * 22)
		b:ball("Hand" .. s, "skin", 0.4, s * 1.05, -0.5, -0.3)
		limb(b, "Leg" .. s, "wood", s * 0.35, -2.1, 0, 1.2, 0.28, 0, 0, 0)
		b:box("Foot" .. s, "wood", 0.5, 0.2, 0.8, s * 0.35, -2.75, -0.2)
	end)
	b:box("Mouth", "black", 0.5, 0.07, 0.06, 0, 1.9, -1.1)
	b:ball("Nose", "bark", 0.12, 0, 2.08, -1.1)
end }

-- 7. cactus elephant ("Lirili Larila"-style)
C.cactus = { id = "cactus", name = "Lirili Larila", group = "costume", category = "Costume", build = function(b)
	b:cylY("Body", "primary", 2.8, 1.5, 0, -0.1, 0).m = "mat"
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		b:cylY("Rib" .. i, "secondary", 2.7, 0.22, math.cos(a) * 0.72, -0.1, math.sin(a) * 0.72).m = "mat"
		b:box("Spine" .. i, "white", 0.04, 0.04, 0.2, math.cos(a) * 0.9, 0.3 + (i % 3) * 0.4, math.sin(a) * 0.9)
	end
	b:ball("Head", "primary", 1.2, 0, 1.6, -0.3).m = "mat"
	b:mirror(function(s)
		b:box("EarFlap" .. s, "secondary", 0.1, 1.0, 0.8, s * 0.9, 1.7, -0.2, 0, s * -18, 0).m = "mat"
		b:box("EarIn" .. s, "detail", 0.05, 0.7, 0.55, s * 0.95, 1.7, -0.22, 0, s * -18, 0).m = "mat"
		eyes(b, 1.8, -0.8, 0.3, 0.26, 0.12)
		limb(b, "Arm" .. s, "primary", s * 0.95, 0.2, 0, 1.3, 0.3, 0, 0, s * 24).m = "mat"
		limb(b, "Leg" .. s, "primary", s * 0.4, -2.0, 0, 1.0, 0.3, 0, 0, 0).m = "mat"
		sneaker(b, "Foot" .. s, s * 0.45, -2.7, -0.1, 0.55)
	end)
	-- trunk
	for i = 0, 3 do b:cylZ("Trunk" .. i, "primary", 0.4, 0.35 - i * 0.04, 0, 1.45 - i * 0.28, -0.95 - i * 0.28).m = "mat" end
	b:ball("TrunkTip", "detail", 0.3, 0, 0.62, -1.9).m = "mat"
	b:cylX("Watch", "glass", 0.12, 0.34, 1.25, -0.5, 0.0)
	b:ball("Flower", "glow", 0.35, 0, 2.3, 0.0)
end }

-- 8. coffee-cup ballerina ("Ballerina Cappuccina"-style)
C.ballerina = { id = "ballerina", name = "Ballerina Cappuccina", group = "costume", category = "Costume", build = function(b)
	b:cylY("CupHead", "white", 1.5, 1.5, 0, 1.5, 0).m = "mat"
	b:cylY("Coffee", "bark", 0.06, 1.3, 0, 2.28, 0)
	b:ball("Foam", "skin", 0.9, 0, 2.3, 0)
	b:cylX("Handle", "white", 0.12, 0.6, 0.85, 1.5, 0).m = "mat"
	eyes(b, 1.5, -0.74, 0.3, 0.3, 0.14)
	b:ball("Blush", "red", 0.18, 0.5, 1.3, -0.72)
	b:ball("BlushB", "red", 0.18, -0.5, 1.3, -0.72)
	b:cylY("Torso", "primary", 1.0, 0.8, 0, 0.35, 0).m = "mat"
	-- tutu: fan of petals
	b:ring(14, 0.85, function(i, a, x, z) b:wedge("Petal" .. i, "primary", 0.5, 0.1, 0.9, x, -0.35, z, 0, -math.deg(a) + 90, 0).m = "mat" end)
	b:ring(14, 0.5, function(i, a, x, z) b:ball("Tulle" .. i, "detail", 0.3, x, -0.28, z).m = "mat" end)
	b:mirror(function(s)
		limb(b, "Arm" .. s, "skin", s * 0.7, 1.0, 0, 1.2, 0.2, 0, 0, s * 70)
		limb(b, "Leg" .. s, "skin", s * 0.25, -1.6, 0, 1.6, 0.2, 0, 0, 0)
		b:wedge("Pointe" .. s, "primary", 0.3, 0.16, 0.5, s * 0.25, -2.55, -0.1, 0, 0, 0).m = "mat"
		b:ball("Heel" .. s, "primary", 0.3, s * 0.25, -2.7, 0).m = "mat"
	end)
	b:ball("Bun", "bark", 0.5, 0, 2.85, 0.1)
	b:ring(5, 0.5, function(i, a, x, z) b:ball("Sparkle" .. i, "glow", 0.1, x * 2.8, 0.3 + i * 0.4, z * 2.8) end)
end }

C.order = {
	"halo", "crown", "horns", "headphones", "catears",
	"wings_angel", "wings_demon", "cape", "chains",
	"circle", "orbit", "chainring",
	"logman", "treeman", "croc", "shark", "cupninja", "banana", "cactus", "ballerina",
}

-- natural looks of the costumes (roles recolour them; "skin", "white", "black" etc. stay fixed) -----------------------------
local function look(primary, secondary, detail, glow, mat)
	return { primary = primary, secondary = secondary, grip = { 40, 40, 46 }, detail = detail, glow = glow, material = mat or "SmoothPlastic", glowAmount = 0.5, decor = 0 }
end
C.logman.look = look({ 186, 128, 70 }, { 130, 86, 46 }, { 90, 60, 36 }, { 255, 190, 80 }, "Wood")
C.treeman.look = look({ 140, 96, 56 }, { 90, 60, 36 }, { 255, 255, 255 }, { 120, 255, 140 }, "Wood")
C.croc.look = look({ 86, 150, 70 }, { 60, 110, 56 }, { 220, 210, 150 }, { 255, 120, 60 })
C.shark.look = look({ 84, 130, 200 }, { 60, 96, 160 }, { 255, 255, 255 }, { 100, 220, 255 })
C.cupninja.look = look({ 90, 70, 50 }, { 60, 50, 40 }, { 255, 255, 255 }, { 255, 200, 120 })
C.banana.look = look({ 248, 214, 70 }, { 210, 170, 40 }, { 255, 240, 160 }, { 255, 230, 120 })
C.cactus.look = look({ 96, 176, 96 }, { 66, 130, 70 }, { 240, 150, 180 }, { 255, 120, 200 })
C.ballerina.look = look({ 255, 190, 215 }, { 240, 150, 190 }, { 255, 230, 240 }, { 255, 140, 220 })
local ACC_LOOK = {
	halo = look({ 255, 224, 120 }, { 220, 180, 80 }, { 255, 245, 200 }, { 255, 232, 140 }),
	crown = look({ 255, 205, 70 }, { 220, 170, 50 }, { 255, 230, 140 }, { 255, 80, 120 }, "Metal"),
	horns = look({ 200, 50, 50 }, { 120, 24, 30 }, { 255, 120, 80 }, { 255, 90, 40 }),
	headphones = look({ 60, 70, 255 }, { 30, 34, 60 }, { 255, 255, 255 }, { 90, 200, 255 }),
	catears = look({ 255, 170, 200 }, { 200, 120, 160 }, { 255, 255, 255 }, { 255, 120, 200 }),
	wings_angel = look({ 255, 255, 255 }, { 210, 160, 255 }, { 255, 230, 140 }, { 190, 120, 255 }),
	wings_demon = look({ 90, 20, 60 }, { 40, 12, 36 }, { 255, 80, 80 }, { 255, 60, 90 }),
	cape = look({ 150, 20, 40 }, { 40, 30, 36 }, { 255, 210, 100 }, { 255, 210, 100 }, "SmoothPlastic"),
	chains = look({ 150, 154, 164 }, { 80, 84, 94 }, { 200, 204, 212 }, { 170, 90, 255 }, "Metal"),
	circle = look({ 170, 90, 255 }, { 100, 50, 200 }, { 220, 170, 255 }, { 190, 110, 255 }),
	orbit = look({ 90, 180, 255 }, { 60, 90, 160 }, { 220, 240, 255 }, { 90, 200, 255 }),
	chainring = look({ 170, 174, 184 }, { 90, 94, 104 }, { 210, 214, 222 }, { 190, 100, 255 }, "Metal"),
}
for id, l in pairs(ACC_LOOK) do C[id].look = l end

-- accessory slots: where each slot attaches, and which models belong to it
C.slots = {
	{ id = "head", label = "Head", anchor = "Head" },
	{ id = "back", label = "Back", anchor = "UpperTorso" },
	{ id = "aura", label = "Aura", anchor = "HumanoidRootPart" },
}

C.styles = {
	{ id = "Classic", look = look({ 255, 255, 255 }, { 210, 214, 224 }, { 255, 224, 120 }, { 255, 232, 140 }) },
	{ id = "Dark", look = look({ 30, 30, 38 }, { 18, 18, 24 }, { 120, 120, 140 }, { 220, 40, 60 }, "Metal") },
	{ id = "Neon", look = look({ 30, 20, 60 }, { 70, 30, 130 }, { 255, 90, 220 }, { 255, 70, 230 }) },
	{ id = "Metallic", look = look({ 210, 214, 224 }, { 150, 156, 168 }, { 240, 200, 120 }, { 255, 240, 200 }, "Foil") },
	{ id = "Minimal", look = look({ 238, 238, 242 }, { 214, 214, 220 }, { 130, 130, 140 }, { 10, 132, 255 }) },
	{ id = "Futuristic", look = look({ 230, 236, 246 }, { 120, 130, 150 }, { 170, 180, 200 }, { 80, 210, 255 }) },
}

return C
